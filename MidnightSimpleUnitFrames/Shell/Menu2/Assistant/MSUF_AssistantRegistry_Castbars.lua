-- Assistant Castbars registry: maps natural-language controls to castbar settings/actions.
-- Registry writes must stay compatible with live castbar runtime and preview refresh helpers.
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

-- Castbars registry domain.
-- Describes backend, size, text/icon, interrupt, and visual controls for assistant matching.
-- Actual castbar frame mutation still belongs to the castbar runtime/bridge modules.
local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS
local AddAliasesForUnit = C.AddAliasesForUnit
local GeneralDB = C.GeneralDB
local ClampNumber = C.ClampNumber
local CallGlobal = C.CallGlobal
local ApplyCastbar = C.ApplyCastbar
local RegisterGeneralBoolean = C.RegisterGeneralBoolean
local RegisterGeneralNumberSetting = C.RegisterGeneralNumberSetting
local RegisterGeneralEnum = C.RegisterGeneralEnum
local RegisterGeneralString = C.RegisterGeneralString

local CASTBAR_KEYS = {
    player = { enable = "enablePlayerCastbar", backend = "castbarPlayerBackend", memory = "castbarPlayerBackendBeforeHide", w = "castbarPlayerBarWidth", h = "castbarPlayerBarHeight", x = "castbarPlayerOffsetX", y = "castbarPlayerOffsetY" },
    target = { enable = "enableTargetCastbar", backend = "castbarTargetBackend", memory = "castbarTargetBackendBeforeHide", w = "castbarTargetBarWidth", h = "castbarTargetBarHeight", x = "castbarTargetOffsetX", y = "castbarTargetOffsetY" },
    focus = { enable = "enableFocusCastbar", backend = "castbarFocusBackend", memory = "castbarFocusBackendBeforeHide", w = "castbarFocusBarWidth", h = "castbarFocusBarHeight", x = "castbarFocusOffsetX", y = "castbarFocusOffsetY" },
    boss = { enable = "enableBossCastbar", backend = "bossCastbarBackend", memory = "bossCastbarBackendBeforeHide", w = "bossCastbarWidth", h = "bossCastbarHeight", x = "bossCastbarOffsetX", y = "bossCastbarOffsetY" },
}

local CASTBAR_DETAIL_FIELDS = {
    player = { time = "showPlayerCastTime", icon = "castbarPlayerShowIcon", text = "castbarPlayerShowSpellName", timeFormat = "castbarPlayerTimeFormat" },
    target = { time = "showTargetCastTime", icon = "castbarTargetShowIcon", text = "castbarTargetShowSpellName", timeFormat = "castbarTargetTimeFormat" },
    focus = { time = "showFocusCastTime", icon = "castbarFocusShowIcon", text = "castbarFocusShowSpellName", timeFormat = "castbarFocusTimeFormat" },
    boss = { time = "showBossCastTime", icon = "showBossCastIcon", text = "showBossCastName", timeFormat = "bossCastTimeFormat" },
}

local CASTBAR_ICON_POSITION_VALUES = { "LEFT", "RIGHT", "INSIDE_LEFT", "INSIDE_RIGHT" }
local CASTBAR_TEXT_POSITION_VALUES = { "LEFT", "CENTER", "RIGHT", "ABOVE", "BELOW" }
local CASTBAR_TEXT_ALIGN_VALUES = { "LEFT", "CENTER", "RIGHT" }
local CASTBAR_TRUNCATE_VALUES = { "AUTO", "CLIP", "NONE" }
local CASTBAR_ICON_BORDER_VALUES = { "NONE", "DARK", "CASTBAR" }
local CASTBAR_TIME_FORMAT_VALUES = { "CURRENT", "ELAPSED", "ELAPSED_MAX", "CURRENT_MAX" }

local CASTBAR_ICON_POSITION_ALIASES = {
    left = "LEFT",
    links = "LEFT",
    right = "RIGHT",
    rechts = "RIGHT",
    ["inside left"] = "INSIDE_LEFT",
    ["inside-left"] = "INSIDE_LEFT",
    ["inside right"] = "INSIDE_RIGHT",
    ["inside-right"] = "INSIDE_RIGHT",
}

local CASTBAR_TEXT_POSITION_ALIASES = {
    left = "LEFT",
    links = "LEFT",
    center = "CENTER",
    centre = "CENTER",
    mitte = "CENTER",
    right = "RIGHT",
    rechts = "RIGHT",
    above = "ABOVE",
    oben = "ABOVE",
    below = "BELOW",
    unten = "BELOW",
}

local CASTBAR_TEXT_ALIGN_ALIASES = {
    left = "LEFT",
    links = "LEFT",
    center = "CENTER",
    centre = "CENTER",
    mitte = "CENTER",
    right = "RIGHT",
    rechts = "RIGHT",
}

local CASTBAR_TRUNCATE_ALIASES = {
    auto = "AUTO",
    automatic = "AUTO",
    automatisch = "AUTO",
    clip = "CLIP",
    clipped = "CLIP",
    ["fixed clip"] = "CLIP",
    none = "NONE",
    off = "NONE",
    aus = "NONE",
    ["no limit"] = "NONE",
    unlimited = "NONE",
}

local CASTBAR_ICON_BORDER_ALIASES = {
    none = "NONE",
    off = "NONE",
    aus = "NONE",
    ["no border"] = "NONE",
    dark = "DARK",
    ["dark border"] = "DARK",
    black = "DARK",
    castbar = "CASTBAR",
    ["castbar border"] = "CASTBAR",
}

local CASTBAR_TIME_FORMAT_ALIASES = {
    current = "CURRENT",
    remaining = "CURRENT",
    rest = "CURRENT",
    verbleibend = "CURRENT",
    elapsed = "ELAPSED",
    vergangen = "ELAPSED",
    ["elapsed total"] = "ELAPSED_MAX",
    ["elapsed max"] = "ELAPSED_MAX",
    ["elapsed / total"] = "ELAPSED_MAX",
    ["remaining total"] = "CURRENT_MAX",
    ["remaining max"] = "CURRENT_MAX",
    ["remaining / total"] = "CURRENT_MAX",
    total = "CURRENT_MAX",
}

local function GetCastbarBackend(unit, g)
    local fn = _G.MSUF_GetCastbarBackend
    if type(fn) == "function" then return fn(unit, g or GeneralDB()) end
    local keys = CASTBAR_KEYS[unit]
    if not keys then return "MSUF" end
    local value = (g or GeneralDB())[keys.backend]
    if value == "HIDE" or value == "BLIZZARD" or value == "MSUF" then return value end
    return ((g or GeneralDB())[keys.enable] == false) and "HIDE" or "MSUF"
end

local function SetCastbarBackend(unit, enabled)
    local g = GeneralDB()
    local keys = CASTBAR_KEYS[unit]
    if not keys then return end
    local backend
    if enabled then
        backend = g[keys.memory]
        if backend ~= "BLIZZARD" and backend ~= "MSUF" then backend = "MSUF" end
        if unit ~= "player" and backend == "BLIZZARD" then backend = "MSUF" end
    else
        local current = GetCastbarBackend(unit, g)
        if current ~= "HIDE" then g[keys.memory] = current end
        backend = "HIDE"
    end
    local fn = _G.MSUF_SetCastbarBackend
    if type(fn) == "function" then
        fn(unit, backend, g)
    else
        g[keys.backend] = backend
        g[keys.enable] = backend == "MSUF"
    end
end

local function NormalizeCastbarBackend(unit, value)
    local fnUnit = _G.MSUF_NormalizeCastbarBackendForUnit
    if type(fnUnit) == "function" then return fnUnit(unit, value) or "MSUF" end
    local fn = _G.MSUF_NormalizeCastbarBackend
    if type(fn) == "function" then
        local backend = fn(value) or "MSUF"
        if backend == "BLIZZARD" and unit ~= "player" then return "HIDE" end
        return backend
    end
    if value == "BLIZZARD" and unit ~= "player" then return "HIDE" end
    if value == "BLIZZARD" or value == "HIDE" or value == "MSUF" then return value end
    return "MSUF"
end

local function SetCastbarProvider(unit, value)
    if unit ~= "player" then return end
    local keys = CASTBAR_KEYS[unit]
    local g = GeneralDB()
    local backend = NormalizeCastbarBackend(unit, value)
    if backend == "HIDE" then backend = "MSUF" end
    if keys.memory then g[keys.memory] = backend end
    local fn = _G.MSUF_SetCastbarBackend
    if type(fn) == "function" then
        fn(unit, backend, g)
    else
        g[keys.backend] = backend
        g[keys.enable] = backend == "MSUF"
    end
end

local function RegisterUnitCastbarBoolean(unit)
    local aliases = {}
    AddAliasesForUnit(aliases, unit, "castbar", "castbar")
    AddAliasesForUnit(aliases, unit, "cast bar", "zauberleiste")
    Registry:RegisterSetting({
        key = "general." .. CASTBAR_KEYS[unit].enable,
        label = UNIT_LABELS[unit] .. " Castbar",
        category = UNIT_LABELS[unit] .. " / Castbar",
        unit = unit,
        frameType = "castbar",
        attribute = "enabled",
        type = "boolean",
        aliases = aliases,
        get = function() return GetCastbarBackend(unit, GeneralDB()) ~= "HIDE" end,
        set = function(value) SetCastbarBackend(unit, value and true or false) end,
        apply = function() ApplyCastbar("MSUF_ASSISTANT_CASTBAR_ENABLE") end,
        combatSafe = false,
    })
end

local function RegisterGeneralNumber(key, unit, frameType, attr, label, defaultValue, minValue, maxValue, aliases)
    Registry:RegisterSetting({
        key = "general." .. key,
        label = UNIT_LABELS[unit] .. " " .. label,
        category = UNIT_LABELS[unit] .. " / Castbar",
        unit = unit,
        frameType = frameType,
        attribute = attr,
        type = "number",
        aliases = aliases,
        min = minValue,
        max = maxValue,
        step = 1,
        get = function()
            local value = tonumber(GeneralDB()[key])
            if value == nil then return defaultValue end
            return value
        end,
        set = function(value)
            GeneralDB()[key] = ClampNumber(value, minValue, maxValue, 1)
        end,
        apply = function() ApplyCastbar("MSUF_ASSISTANT_CASTBAR_GEOMETRY") end,
        combatSafe = false,
    })
end

local function RegisterGeneralEnumSetting(key, unit, frameType, attr, label, defaultValue, values, aliases, valueAliases)
    RegisterGeneralEnum(key, attr, UNIT_LABELS[unit] .. " " .. label, defaultValue, values, aliases, {
        category = UNIT_LABELS[unit] .. " / Castbar",
        unit = unit,
        frameType = frameType,
        valueAliases = valueAliases,
        reason = "MSUF_ASSISTANT_CASTBAR_DETAIL",
        apply = ApplyCastbar,
    })
end

local function RegisterCastbarUnitGeneralBoolean(unit, dbKey, attr, label, defaultValue, aliases)
    Registry:RegisterSetting({
        key = "general." .. dbKey,
        label = UNIT_LABELS[unit] .. " " .. label,
        category = UNIT_LABELS[unit] .. " / Castbar",
        unit = unit,
        frameType = "castbar",
        attribute = attr,
        type = "boolean",
        aliases = aliases,
        get = function()
            local value = GeneralDB()[dbKey]
            if value == nil then return defaultValue and true or false end
            return value and true or false
        end,
        set = function(value)
            GeneralDB()[dbKey] = value and true or false
        end,
        apply = function() ApplyCastbar("MSUF_ASSISTANT_CASTBAR_DETAIL") end,
        combatSafe = false,
    })
end

local function RegisterPlayerCastbarProvider()
    local unit = "player"
    local keys = CASTBAR_KEYS[unit]
    local aliases = {}
    AddAliasesForUnit(aliases, unit, "castbar provider")
    AddAliasesForUnit(aliases, unit, "cast bar provider")
    AddAliasesForUnit(aliases, unit, "castbar backend")
    Registry:RegisterSetting({
        key = "general." .. keys.backend,
        label = "Player Castbar Provider",
        category = "Player / Castbar",
        unit = unit,
        frameType = "castbar",
        attribute = "provider",
        type = "enum",
        aliases = aliases,
        values = { "MSUF", "BLIZZARD" },
        valueAliases = {
            msuf = "MSUF",
            ["msuf castbar"] = "MSUF",
            default = "MSUF",
            blizzard = "BLIZZARD",
            ["blizzard castbar"] = "BLIZZARD",
        },
        get = function()
            local backend = NormalizeCastbarBackend(unit, GetCastbarBackend(unit, GeneralDB()))
            if backend == "BLIZZARD" then return "BLIZZARD" end
            if backend == "MSUF" then return "MSUF" end
            local remembered = keys.memory and NormalizeCastbarBackend(unit, GeneralDB()[keys.memory]) or nil
            return remembered == "BLIZZARD" and "BLIZZARD" or "MSUF"
        end,
        set = function(value) SetCastbarProvider(unit, value) end,
        apply = function()
            ApplyCastbar("MSUF_ASSISTANT_CASTBAR_PROVIDER")
            CallGlobal("MSUF_SuppressBlizzardPlayerCastbars")
        end,
        combatSafe = false,
    })
end

for unit, keys in pairs(CASTBAR_KEYS) do
    RegisterUnitCastbarBoolean(unit)
    local aliases = {}
    AddAliasesForUnit(aliases, unit, "castbar width", "castbar breite")
    AddAliasesForUnit(aliases, unit, "cast bar width", "zauberleiste breite")
    RegisterGeneralNumber(keys.w, unit, "castbar", "width", "Castbar Width", unit == "boss" and 176 or (unit == "focus" and 175 or 272), 40, 900, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, unit, "castbar height", "castbar hoehe")
    AddAliasesForUnit(aliases, unit, "cast bar height", "zauberleiste hoehe")
    RegisterGeneralNumber(keys.h, unit, "castbar", "height", "Castbar Height", unit == "boss" and 12 or 18, 6, 80, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, unit, "castbar x", "castbar x")
    AddAliasesForUnit(aliases, unit, "castbar x offset", "castbar x versatz")
    RegisterGeneralNumber(keys.x, unit, "castbar", "offsetX", "Castbar X", 0, -1000, 1000, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, unit, "castbar y", "castbar y")
    AddAliasesForUnit(aliases, unit, "castbar y offset", "castbar y versatz")
    RegisterGeneralNumber(keys.y, unit, "castbar", "offsetY", "Castbar Y", 0, -1000, 1000, aliases)
end

RegisterPlayerCastbarProvider()

for unit, fields in pairs(CASTBAR_DETAIL_FIELDS) do
    local aliases = {}
    AddAliasesForUnit(aliases, unit, "castbar time")
    AddAliasesForUnit(aliases, unit, "cast time")
    AddAliasesForUnit(aliases, unit, "show cast time")
    RegisterCastbarUnitGeneralBoolean(unit, fields.time, "time", "Cast Time Text", true, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, unit, "castbar icon")
    AddAliasesForUnit(aliases, unit, "cast icon")
    AddAliasesForUnit(aliases, unit, "spell icon")
    RegisterCastbarUnitGeneralBoolean(unit, fields.icon, "icon", "Castbar Icon", true, aliases)

    aliases = {}
    AddAliasesForUnit(aliases, unit, "castbar text")
    AddAliasesForUnit(aliases, unit, "castbar name")
    AddAliasesForUnit(aliases, unit, "castbar spell name")
    AddAliasesForUnit(aliases, unit, "castbar spell text")
    AddAliasesForUnit(aliases, unit, "spell name")
    AddAliasesForUnit(aliases, unit, "spell name text")
    RegisterCastbarUnitGeneralBoolean(unit, fields.text, "text", "Castbar Spell Text", true, aliases)
end

local function CastbarAliases(noun, ...)
    local out = {
        "castbar " .. noun,
        "cast bar " .. noun,
        noun .. " castbar",
        noun .. " cast bar",
    }
    for i = 1, select("#", ...) do out[#out + 1] = select(i, ...) end
    return out
end

local function ApplyCastbarTextures(reason)
    CallGlobal("MSUF_UpdateCastbarTextures_Immediate")
    CallGlobal("MSUF_UpdateCastbarTextures")
    CallGlobal("MSUF_UpdateCastbarVisuals_Immediate")
    CallGlobal("MSUF_UpdateCastbarVisuals")
    CallGlobal("MSUF_UpdateBossCastbarPreview")
    ApplyCastbar(reason or "MSUF2_CASTBAR_TEXTURES")
end

local function ApplyCastbarOutline(reason)
    CallGlobal("MSUF_ApplyCastbarOutlineToAll", true)
    ApplyCastbarTextures(reason or "MSUF2_CASTBAR_OUTLINE")
end

local function ApplyFocusKick(reason)
    CallGlobal("MSUF_UpdateFocusKickIconOptions")
    ApplyCastbar(reason or "MSUF2_FOCUS_KICK")
end

local function ApplyFocusKickText(reason)
    CallGlobal("MSUF_FocusKick_ApplyTimeTextFont")
    ApplyFocusKick(reason or "MSUF2_FOCUS_KICK_TEXT")
end

local function RegisterCastbarBoolean(dbKey, attr, label, defaultValue, aliases, opts)
    opts = opts or {}
    opts.category = opts.category or "Appearance / Castbars"
    opts.frameType = opts.frameType or "castbar"
    opts.apply = opts.apply or ApplyCastbar
    RegisterGeneralBoolean(dbKey, attr, label, defaultValue, aliases, opts)
end

local function RegisterCastbarNumber(dbKey, attr, label, defaultValue, minValue, maxValue, aliases, opts)
    opts = opts or {}
    opts.category = opts.category or "Appearance / Castbars"
    opts.frameType = opts.frameType or "castbar"
    opts.apply = opts.apply or ApplyCastbar
    RegisterGeneralNumberSetting(dbKey, attr, label, defaultValue, minValue, maxValue, aliases, opts)
end

local function RegisterCastbarEnum(dbKey, attr, label, defaultValue, values, aliases, opts)
    opts = opts or {}
    opts.category = opts.category or "Appearance / Castbars"
    opts.frameType = opts.frameType or "castbar"
    opts.apply = opts.apply or ApplyCastbar
    RegisterGeneralEnum(dbKey, attr, label, defaultValue, values, aliases, opts)
end

local function RegisterCastbarString(dbKey, attr, label, defaultValue, aliases, opts)
    opts = opts or {}
    opts.category = opts.category or "Appearance / Castbars"
    opts.frameType = opts.frameType or "castbar"
    opts.apply = opts.apply or ApplyCastbar
    RegisterGeneralString(dbKey, attr, label, defaultValue, aliases, opts)
end

local function RegisterCastbarNumericBoolean(dbKey, attr, label, defaultValue, aliases, opts)
    opts = opts or {}
    Registry:RegisterSetting({
        key = "general." .. dbKey,
        label = label,
        category = opts.category or "Appearance / Castbars",
        unit = opts.unit or "global",
        frameType = opts.frameType or "castbar",
        attribute = attr,
        type = "boolean",
        aliases = aliases,
        get = function()
            local value = tonumber(GeneralDB()[dbKey])
            if value == nil then return defaultValue and true or false end
            return value ~= 0
        end,
        set = function(value)
            GeneralDB()[dbKey] = value and 1 or 0
        end,
        apply = function()
            if opts.apply then opts.apply(opts.reason or ("MSUF_ASSISTANT_" .. dbKey)) else ApplyCastbar(opts.reason or ("MSUF_ASSISTANT_" .. dbKey)) end
        end,
        combatSafe = opts.combatSafe == true,
        description = opts.description,
    })
end

local function RegisterCastbarDetailNumbers()
    RegisterCastbarNumber("castbarIconSize", "iconSize", "Castbar Icon Size", 0, 0, 128, CastbarAliases("icon size", "castbar icon size", "spell icon size"), {
        reason = "MSUF2_CASTBAR_ICON_SIZE",
        apply = ApplyCastbarTextures,
        description = "Global castbar icon size override. 0 uses the castbar height fallback.",
    })
    RegisterCastbarNumber("castbarIconOffsetX", "iconOffsetX", "Castbar Icon X Offset", 0, -300, 300, CastbarAliases("icon x", "icon x offset", "castbar icon x", "castbar icon x offset"), {
        reason = "MSUF2_CASTBAR_ICON_X",
        apply = ApplyCastbarTextures,
    })
    RegisterCastbarNumber("castbarIconOffsetY", "iconOffsetY", "Castbar Icon Y Offset", 0, -300, 300, CastbarAliases("icon y", "icon y offset", "castbar icon y", "castbar icon y offset"), {
        reason = "MSUF2_CASTBAR_ICON_Y",
        apply = ApplyCastbarTextures,
    })
    RegisterCastbarNumber("castbarSpellNameFontSize", "spellNameFontSize", "Castbar Spell Name Font Size", 0, 0, 48, CastbarAliases("spell name font size", "castbar text font size", "castbar spell text font size", "spell text size"), {
        reason = "MSUF2_CASTBAR_SPELL_FONT_SIZE",
        apply = ApplyCastbar,
        description = "Global castbar spell-name font override. 0 uses the global font size fallback.",
    })
    RegisterCastbarNumber("castbarTimeFontSize", "timeFontSize", "Castbar Time Font Size", 0, 0, 48, CastbarAliases("time font size", "castbar time font size", "castbar timer font size", "castbar time text size"), {
        reason = "MSUF2_CASTBAR_TIME_FONT_SIZE",
        apply = ApplyCastbar,
        description = "Global castbar time font override. 0 uses the spell-name/global font size fallback.",
    })

    local detail = {
        player = { prefix = "castbarPlayer", iconDefault = 0, textX = 0, textY = 0, timeX = -2, timeY = 0 },
        target = { prefix = "castbarTarget", iconDefault = 0, textX = 0, textY = 0, timeX = -2, timeY = 0 },
        focus = { prefix = "castbarFocus", iconDefault = 0, textX = 0, textY = 0, timeX = -2, timeY = 0 },
        boss = { prefix = "bossCast", iconDefault = 0, textX = 0, textY = 0, timeX = 0, timeY = 0 },
    }
    for unit, spec in pairs(detail) do
        local aliases
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar icon size"); AddAliasesForUnit(aliases, unit, "castbar spell icon size")
        RegisterGeneralNumber(spec.prefix .. "IconSize", unit, "castbar", "iconSize", "Castbar Icon Size", spec.iconDefault, 0, 128, aliases)
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar icon position"); AddAliasesForUnit(aliases, unit, "castbar spell icon position")
        RegisterGeneralEnumSetting(spec.prefix .. "IconPosition", unit, "castbar", "iconPosition", "Castbar Icon Position", "LEFT", CASTBAR_ICON_POSITION_VALUES, aliases, CASTBAR_ICON_POSITION_ALIASES)
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar icon x"); AddAliasesForUnit(aliases, unit, "castbar icon x offset")
        RegisterGeneralNumber(spec.prefix .. "IconOffsetX", unit, "castbar", "iconOffsetX", "Castbar Icon X Offset", 0, -300, 300, aliases)
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar icon y"); AddAliasesForUnit(aliases, unit, "castbar icon y offset")
        RegisterGeneralNumber(spec.prefix .. "IconOffsetY", unit, "castbar", "iconOffsetY", "Castbar Icon Y Offset", 0, -300, 300, aliases)
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar icon spacing"); AddAliasesForUnit(aliases, unit, "castbar spell icon spacing")
        RegisterGeneralNumber(spec.prefix .. "IconSpacing", unit, "castbar", "iconSpacing", "Castbar Icon Spacing", 1, 0, 40, aliases)
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar icon border"); AddAliasesForUnit(aliases, unit, "castbar icon border style")
        RegisterGeneralEnumSetting(spec.prefix .. "IconBorderStyle", unit, "castbar", "iconBorderStyle", "Castbar Icon Border Style", "NONE", CASTBAR_ICON_BORDER_VALUES, aliases, CASTBAR_ICON_BORDER_ALIASES)

        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar spell name position"); AddAliasesForUnit(aliases, unit, "castbar spell text position"); AddAliasesForUnit(aliases, unit, "castbar text position")
        RegisterGeneralEnumSetting(spec.prefix .. "SpellNamePosition", unit, "castbar", "spellNamePosition", "Castbar Spell Name Position", "LEFT", CASTBAR_TEXT_POSITION_VALUES, aliases, CASTBAR_TEXT_POSITION_ALIASES)
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar text x"); AddAliasesForUnit(aliases, unit, "castbar spell name x"); AddAliasesForUnit(aliases, unit, "castbar spell text x"); AddAliasesForUnit(aliases, unit, "castbar text x offset")
        RegisterGeneralNumber(spec.prefix .. "TextOffsetX", unit, "castbar", "textOffsetX", "Castbar Spell Text X Offset", spec.textX, -300, 300, aliases)
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar text y"); AddAliasesForUnit(aliases, unit, "castbar spell name y"); AddAliasesForUnit(aliases, unit, "castbar spell text y"); AddAliasesForUnit(aliases, unit, "castbar text y offset")
        RegisterGeneralNumber(spec.prefix .. "TextOffsetY", unit, "castbar", "textOffsetY", "Castbar Spell Text Y Offset", spec.textY, -300, 300, aliases)
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar spell name alignment"); AddAliasesForUnit(aliases, unit, "castbar spell text alignment"); AddAliasesForUnit(aliases, unit, "castbar text alignment")
        RegisterGeneralEnumSetting(spec.prefix .. "SpellNameAlign", unit, "castbar", "spellNameAlign", "Castbar Spell Name Alignment", "LEFT", CASTBAR_TEXT_ALIGN_VALUES, aliases, CASTBAR_TEXT_ALIGN_ALIASES)
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar spell name font size"); AddAliasesForUnit(aliases, unit, "castbar text font size"); AddAliasesForUnit(aliases, unit, "castbar spell text size")
        RegisterGeneralNumber(spec.prefix .. "SpellNameFontSize", unit, "castbar", "spellNameFontSize", "Castbar Spell Name Font Size", 0, 0, 48, aliases)
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar spell name max width"); AddAliasesForUnit(aliases, unit, "castbar spell text max width"); AddAliasesForUnit(aliases, unit, "castbar text max width")
        RegisterGeneralNumber(spec.prefix .. "SpellNameMaxWidth", unit, "castbar", "spellNameMaxWidth", "Castbar Spell Name Max Width", 0, 0, 500, aliases)
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar spell name truncate"); AddAliasesForUnit(aliases, unit, "castbar spell text truncate"); AddAliasesForUnit(aliases, unit, "castbar text truncate")
        RegisterGeneralEnumSetting(spec.prefix .. "SpellNameTruncate", unit, "castbar", "spellNameTruncate", "Castbar Spell Name Truncate Behavior", "AUTO", CASTBAR_TRUNCATE_VALUES, aliases, CASTBAR_TRUNCATE_ALIASES)

        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar time format"); AddAliasesForUnit(aliases, unit, "cast time format"); AddAliasesForUnit(aliases, unit, "castbar timer format")
        RegisterGeneralEnumSetting(CASTBAR_DETAIL_FIELDS[unit].timeFormat, unit, "castbar", "timeFormat", "Castbar Time Format", "CURRENT", CASTBAR_TIME_FORMAT_VALUES, aliases, CASTBAR_TIME_FORMAT_ALIASES)
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar time position"); AddAliasesForUnit(aliases, unit, "castbar time text position"); AddAliasesForUnit(aliases, unit, "castbar timer position")
        RegisterGeneralEnumSetting(spec.prefix .. "TimePosition", unit, "castbar", "timePosition", "Castbar Time Position", "RIGHT", CASTBAR_TEXT_POSITION_VALUES, aliases, CASTBAR_TEXT_POSITION_ALIASES)
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar time x"); AddAliasesForUnit(aliases, unit, "castbar time text x"); AddAliasesForUnit(aliases, unit, "castbar timer x"); AddAliasesForUnit(aliases, unit, "castbar time x offset")
        RegisterGeneralNumber(spec.prefix .. "TimeOffsetX", unit, "castbar", "timeOffsetX", "Castbar Time Text X Offset", spec.timeX, -300, 300, aliases)
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar time y"); AddAliasesForUnit(aliases, unit, "castbar time text y"); AddAliasesForUnit(aliases, unit, "castbar timer y"); AddAliasesForUnit(aliases, unit, "castbar time y offset")
        RegisterGeneralNumber(spec.prefix .. "TimeOffsetY", unit, "castbar", "timeOffsetY", "Castbar Time Text Y Offset", spec.timeY, -300, 300, aliases)
        aliases = {}; AddAliasesForUnit(aliases, unit, "castbar time font size"); AddAliasesForUnit(aliases, unit, "castbar timer font size"); AddAliasesForUnit(aliases, unit, "castbar time text size")
        RegisterGeneralNumber(spec.prefix .. "TimeFontSize", unit, "castbar", "timeFontSize", "Castbar Time Font Size", 0, 0, 48, aliases)
    end
end

RegisterCastbarDetailNumbers()

RegisterCastbarBoolean("castbarInterruptShake", "interruptShake", "Shake on Interrupt", false, CastbarAliases("interrupt shake", "shake on interrupt"), {
    reason = "MSUF2_CASTBAR_SHAKE",
})
RegisterCastbarNumber("castbarShakeStrength", "shakeStrength", "Shake Strength", 8, 0, 30, CastbarAliases("shake strength", "interrupt shake strength"), {
    reason = "MSUF2_CASTBAR_SHAKE_STRENGTH",
})
RegisterCastbarBoolean("castbarUnifiedDirection", "unifiedDirection", "Always Use Fill Direction For All Casts", false, CastbarAliases("unified fill direction", "same fill direction for channels"), {
    reason = "MSUF2_CASTBAR_UNIFIED_DIRECTION",
})
RegisterCastbarEnum("castbarFillDirection", "fillDirection", "Castbar Fill Direction", "RTL", { "RTL", "LTR" }, CastbarAliases("fill direction", "direction"), {
    reason = "MSUF2_CASTBAR_FILL_DIRECTION",
    valueAliases = {
        left = "RTL",
        ["right to left"] = "RTL",
        rtl = "RTL",
        default = "RTL",
        right = "LTR",
        ["left to right"] = "LTR",
        ltr = "LTR",
    },
})
RegisterCastbarBoolean("castbarOpositeDirectionTarget", "targetOppositeDirection", "Use Opposite Fill Direction For Target", false, CastbarAliases("target opposite fill direction", "opposite target direction"), {
    reason = "MSUF2_CASTBAR_TARGET_DIRECTION",
})
RegisterCastbarBoolean("castbarShowChannelTicks", "channelTicks", "Show Channel Tick Lines", false, CastbarAliases("channel ticks", "channel tick lines"), {
    reason = "MSUF2_CASTBAR_TICKS",
})

RegisterCastbarString("castbarTexture", "texture", "Castbar Texture", "Blizzard", CastbarAliases("texture", "foreground texture", "sharedmedia texture"), {
    reason = "MSUF2_CASTBAR_TEXTURE",
    apply = ApplyCastbarTextures,
    description = "SharedMedia texture name; values are provided dynamically by the UI.",
})
RegisterCastbarString("castbarBackgroundTexture", "backgroundTexture", "Castbar Background Texture", "Blizzard", CastbarAliases("background texture", "background texture", "bg texture"), {
    reason = "MSUF2_CASTBAR_BG_TEXTURE",
    apply = ApplyCastbarTextures,
    description = "SharedMedia texture name; values are provided dynamically by the UI.",
})
RegisterCastbarNumber("castbarOutlineThickness", "outline", "Castbar Outline Thickness", 1, 0, 6, CastbarAliases("outline thickness", "border thickness"), {
    reason = "MSUF2_CASTBAR_OUTLINE",
    apply = ApplyCastbarOutline,
})
RegisterCastbarBoolean("castbarShowGlow", "glow", "Show Castbar Glow Effect", false, CastbarAliases("glow", "glow effect"), {
    reason = "MSUF2_CASTBAR_GLOW",
    apply = ApplyCastbarTextures,
})
RegisterCastbarBoolean("castbarShowLatency", "latency", "Show Latency Indicator", true, CastbarAliases("latency", "latency indicator"), {
    reason = "MSUF2_CASTBAR_LATENCY",
    apply = ApplyCastbarTextures,
})
RegisterCastbarBoolean("castbarShowSpark", "spark", "Show Spark", false, CastbarAliases("spark", "leading edge highlight"), {
    reason = "MSUF2_CASTBAR_SPARK",
    apply = ApplyCastbarTextures,
})
RegisterCastbarBoolean("castbarSparkOverflow", "sparkOverflow", "Spark Extends Beyond Bar", true, CastbarAliases("spark overflow", "spark beyond bar"), {
    reason = "MSUF2_CASTBAR_SPARK_OVERFLOW",
    apply = ApplyCastbarTextures,
})

RegisterCastbarBoolean("empowerColorStages", "empoweredStageColor", "Add Color To Empowered Stages", true, CastbarAliases("empowered stage colors", "empower color stages"), {
    reason = "MSUF2_CASTBAR_EMPOWER_COLOR",
})
RegisterCastbarBoolean("empowerStageBlink", "empoweredStageBlink", "Add Stage Blink For Empowered Casts", true, CastbarAliases("empowered stage blink", "empower stage blink"), {
    reason = "MSUF2_CASTBAR_EMPOWER_BLINK",
})
RegisterCastbarNumber("empowerStageBlinkTime", "empoweredStageBlinkTime", "Stage Blink Time", 0.25, 0.05, 1.00, CastbarAliases("stage blink time", "empowered blink time"), {
    step = 0.01,
    reason = "MSUF2_CASTBAR_EMPOWER_TIME",
})

RegisterCastbarNumericBoolean("castbarSpellNameShortening", "spellNameShortening", "Spell Name Shortening", false, CastbarAliases("spell name shortening", "shorten spell names"), {
    reason = "MSUF2_CASTBAR_NAME_SHORTEN",
})
RegisterCastbarNumber("castbarSpellNameMaxLen", "spellNameMaxLength", "Max Spell Name Length", 30, 6, 30, CastbarAliases("max spell name length", "spell name max length"), {
    reason = "MSUF2_CASTBAR_NAME_MAX",
})
RegisterCastbarNumber("castbarSpellNameReservedSpace", "spellNameReservedSpace", "Reserved Spell Name Space", 8, 0, 30, CastbarAliases("reserved spell name space", "spell name reserved space"), {
    reason = "MSUF2_CASTBAR_NAME_RESERVED",
})

RegisterCastbarBoolean("enableFocusKickIcon", "focusKick", "Focus Interrupt Tracker", false, CastbarAliases("focus interrupt tracker", "focus kick icon", "focus kick tracker"), {
    reason = "MSUF2_FOCUS_KICK_ENABLE",
    apply = ApplyFocusKick,
})
Registry:RegisterSetting({
    key = "runtime.focusKickPreview",
    label = "Focus Kick On-Screen Preview",
    category = "Appearance / Castbars",
    unit = "global",
    frameType = "castbar",
    attribute = "focusKickPreview",
    type = "boolean",
    aliases = CastbarAliases("focus kick preview", "focus interrupt preview", "show focus kick preview", "show on-screen preview", "on-screen preview"),
    get = function()
        local fn = _G.MSUF_FocusKick_IsPreviewEnabled
        return type(fn) == "function" and (fn() and true or false) or false
    end,
    set = function(value)
        local fn = _G.MSUF_FocusKick_SetPreviewEnabled
        if type(fn) == "function" then fn(value and true or false) end
    end,
    apply = function() end,
    combatSafe = true,
    verifyAfterSet = true,
    description = "Runtime preview toggle; backed by MSUF_FocusKick_SetPreviewEnabled when loaded.",
})
RegisterCastbarNumber("focusKickIconWidth", "focusKickWidth", "Focus Kick Width", 40, 16, 128, CastbarAliases("focus kick width", "focus interrupt tracker width"), {
    reason = "MSUF2_FOCUS_KICK_WIDTH",
    apply = ApplyFocusKick,
})
RegisterCastbarNumber("focusKickIconHeight", "focusKickHeight", "Focus Kick Height", 40, 16, 128, CastbarAliases("focus kick height", "focus interrupt tracker height"), {
    reason = "MSUF2_FOCUS_KICK_HEIGHT",
    apply = ApplyFocusKick,
})
RegisterCastbarNumber("focusKickTextSize", "focusKickTextSize", "Focus Kick Text Size", 12, 8, 24, CastbarAliases("focus kick text size", "focus interrupt tracker text size"), {
    reason = "MSUF2_FOCUS_KICK_TEXT",
    apply = ApplyFocusKickText,
})
RegisterCastbarNumber("focusKickIconOffsetX", "focusKickOffsetX", "Focus Kick X Offset", 300, -500, 500, CastbarAliases("focus kick x offset", "focus interrupt tracker x"), {
    reason = "MSUF2_FOCUS_KICK_X",
    apply = ApplyFocusKick,
})
RegisterCastbarNumber("focusKickIconOffsetY", "focusKickOffsetY", "Focus Kick Y Offset", 0, -500, 500, CastbarAliases("focus kick y offset", "focus interrupt tracker y"), {
    reason = "MSUF2_FOCUS_KICK_Y",
    apply = ApplyFocusKick,
})

RegisterCastbarBoolean("kickReadyShowTarget", "kickReadyTarget", "Show Interrupt Ready On Target Castbar", false, CastbarAliases("target interrupt ready", "show interrupt ready on target"), {
    reason = "MSUF2_KICK_READY_ENABLE",
})
RegisterCastbarBoolean("kickReadyShowFocus", "kickReadyFocus", "Show Interrupt Ready On Focus Castbar", false, CastbarAliases("focus interrupt ready", "show interrupt ready on focus"), {
    reason = "MSUF2_KICK_READY_ENABLE",
})
RegisterCastbarBoolean("kickReadyShowBoss", "kickReadyBoss", "Show Interrupt Ready On Boss Castbars", false, CastbarAliases("boss interrupt ready", "show interrupt ready on boss"), {
    reason = "MSUF2_KICK_READY_ENABLE",
})
RegisterCastbarEnum("kickReadyStyle", "kickReadyStyle", "Interrupt Ready Indicator Style", "border", { "border", "box" }, CastbarAliases("interrupt ready style", "interrupt ready style", "kick ready style", "interrupt ready indicator style"), {
    reason = "MSUF2_KICK_READY_STYLE",
    valueAliases = {
        border = "border",
        outline = "border",
        box = "box",
        square = "box",
    },
})
RegisterCastbarNumber("kickReadySize", "kickReadySize", "Interrupt Ready Indicator Size", 16, 8, 32, CastbarAliases("interrupt ready size", "interrupt ready size", "kick ready size", "interrupt ready indicator size"), {
    reason = "MSUF2_KICK_READY_SIZE",
})
RegisterCastbarBoolean("kickReadyAutoSize", "kickReadyAutoSize", "Auto-Size Interrupt Ready Indicator", true, CastbarAliases("interrupt ready auto size", "interrupt ready auto size", "kick ready auto size", "auto size interrupt ready indicator"), {
    reason = "MSUF2_KICK_READY_AUTO",
})
RegisterCastbarEnum("kickReadyAnchor", "kickReadyAnchor", "Interrupt Ready Indicator Anchor", "RIGHT", { "RIGHT", "LEFT", "TOP", "BOTTOM" }, CastbarAliases("interrupt ready anchor", "interrupt ready anchor", "kick ready anchor", "interrupt ready indicator anchor"), {
    reason = "MSUF2_KICK_READY_ANCHOR",
    valueAliases = {
        right = "RIGHT",
        left = "LEFT",
        top = "TOP",
        bottom = "BOTTOM",
        oben = "TOP",
        unten = "BOTTOM",
        links = "LEFT",
        rechts = "RIGHT",
    },
})
RegisterCastbarNumber("kickReadyOffsetX", "kickReadyOffsetX", "Interrupt Ready X Offset", 4, -50, 50, CastbarAliases("interrupt ready x offset", "interrupt ready x offset", "kick ready x", "interrupt ready indicator x offset"), {
    reason = "MSUF2_KICK_READY_X",
})
RegisterCastbarNumber("kickReadyOffsetY", "kickReadyOffsetY", "Interrupt Ready Y Offset", 0, -50, 50, CastbarAliases("interrupt ready y offset", "interrupt ready y offset", "kick ready y", "interrupt ready indicator y offset"), {
    reason = "MSUF2_KICK_READY_Y",
})

local CASTBAR_PREVIEW_UNITS = { player = true, target = true, focus = true, boss = true }
local CASTBAR_PREVIEW_TYPES = { normal = true, channel = true, empowered = true }

local function NormalizeCastbarPreviewUnit(unit)
    unit = tostring(unit or ""):lower()
    if unit == "boss1" or unit == "bosses" then unit = "boss" end
    return CASTBAR_PREVIEW_UNITS[unit] and unit or "player"
end

local function NormalizeCastbarPreviewType(kind)
    kind = tostring(kind or ""):lower()
    if kind == "channeled" or kind == "channelled" then kind = "channel" end
    if kind == "empower" then kind = "empowered" end
    return CASTBAR_PREVIEW_TYPES[kind] and kind or "normal"
end

local function OpenCastbarPage()
    if M and type(M.Open) == "function" then
        return M.Open("opt_castbar") ~= false
    end
    if M and type(M.SelectPage) == "function" then
        return M.SelectPage("opt_castbar") ~= false
    end
    return false
end

Registry:RegisterAction({
    key = "preview_castbar",
    label = "Preview Castbar",
    type = "preview",
    category = "Appearance / Castbars",
    aliases = {
        "preview castbar", "castbar preview", "show castbar preview",
        "preview player castbar", "preview target castbar", "preview focus castbar", "preview boss castbar",
        "preview channel castbar", "preview empowered castbar", "preview castbar interrupt",
    },
    combatSafe = true,
    run = function(args)
        args = type(args) == "table" and args or {}
        local unit = NormalizeCastbarPreviewUnit(args.unit)
        local kind = NormalizeCastbarPreviewType(args.kind or args.castType)
        M._msuf2CastbarPreviewUnit = unit
        M._msuf2CastbarPreviewType = kind
        if M and type(M.SetCastbarPreviewUnit) == "function" then M.SetCastbarPreviewUnit(unit) end
        if M and type(M.SetCastbarPreviewType) == "function" then M.SetCastbarPreviewType(kind) end
        if args.interrupt then
            if M and type(M.PlayCastbarPreviewInterrupt) == "function" then
                M.PlayCastbarPreviewInterrupt()
            elseif M then
                M._msuf2CastbarPreviewInterruptPending = true
            end
        end
        local opened = OpenCastbarPage()
        local unitLabel = UNIT_LABELS[unit] or unit
        local typeLabel = kind == "channel" and "channel" or (kind == "empowered" and "empowered" or "normal")
        local suffix = args.interrupt and " with interrupt feedback" or ""
        return true, (opened and "Opened" or "Prepared") .. " " .. tostring(unitLabel) .. " " .. typeLabel .. " castbar preview" .. suffix .. "."
    end,
})

Registry:RegisterAction({
    key = "reset_focus_kick_position",
    label = "Reset Focus Kick Position",
    type = "reset",
    category = "Appearance / Castbars",
    aliases = {
        "reset focus kick position",
        "reset focus interrupt tracker position",
        "focus kick reset position",
    },
    combatSafe = false,
    captureSnapshot = true,
    run = function()
        local g = GeneralDB()
        g.focusKickIconOffsetX = 300
        g.focusKickIconOffsetY = 0
        CallGlobal("MSUF_UpdateFocusKickIconOptions")
        ApplyCastbar("MSUF2_FOCUS_KICK_RESET")
        return true, "Done. Reset Focus Kick position."
    end,
})

C.CASTBAR_KEYS = CASTBAR_KEYS
C.GetCastbarBackend = GetCastbarBackend
