-- Assistant registry core: shared DB accessors, value parsers, aliases, and apply helpers.
-- Cold-path registry domains should call these helpers instead of duplicating Menu2 semantics.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry

-- Shared helper layer for Assistant registry domains.
-- Domain files below this one should reuse these DB readers, clamps, aliases, and apply
-- callbacks so natural-language settings stay consistent with the real Menu2 controls.
local CoreData = A.RegistryCoreData
if type(CoreData) ~= "table" then return end

local UNIT_LABELS = CoreData.UNIT_LABELS
local UNIT_ALIASES = CoreData.UNIT_ALIASES
local AURA_LANE_FIELDS = CoreData.AURA_LANE_FIELDS
local AURA_UNIT_FLAGS = CoreData.AURA_UNIT_FLAGS
A.UnitAliases = UNIT_ALIASES
A.UnitLabels = UNIT_LABELS

local ENUM_DISPLAY_LABELS = {
    NONE = "none",
    ALL = "all",
    DEFAULT = "default",
    CUSTOM = "custom",
    TOPLEFT = "top left",
    TOPRIGHT = "top right",
    BOTTOMLEFT = "bottom left",
    BOTTOMRIGHT = "bottom right",
    CENTER = "center",
    TOP = "top",
    BOTTOM = "bottom",
    LEFT = "left",
    RIGHT = "right",
    NAMELEFT = "name left",
    NAMERIGHT = "name right",
    CLASS_COLOR = "class color",
    CLASS = "class",
    RAID_BUFFS = "raid buffs",
    RAID_DEBUFFS = "raid debuffs",
    HELPFUL = "helpful",
    HARMFUL = "harmful",
    PLAYER = "player",
    ["HELPFUL|PLAYER"] = "helpful player",
    ["HARMFUL|PLAYER"] = "harmful player",
    BLIZZARD = "Blizzard",
    CLASSIC = "classic",
    MIDNIGHT = "Midnight",
    MSUF = "MSUF",
    GAME = "GameTooltip",
    OOC = "out of combat",
    LTR = "left to right",
    RTL = "right to left",
    VERTICAL_DOWN = "vertical down",
    VERTICAL_UP = "vertical up",
    HORIZONTAL_RIGHT = "horizontal right",
    HORIZONTAL_LEFT = "horizontal left",
    RIGHTDOWN = "right then down",
    RIGHTUP = "right then up",
    LEFTDOWN = "left then down",
    LEFTUP = "left then up",
    bossTarget = "boss target",
}

local function HumanizeKeyLabel(key)
    key = tostring(key or "")
    if ENUM_DISPLAY_LABELS[key] then return ENUM_DISPLAY_LABELS[key] end
    key = key:gsub("^uf_", ""):gsub("^gf_", "")
    if key == "targettarget" then return "Target of Target" end
    if key == "focustarget" then return "Focus Target" end
    if key == "mythicraid" then return "Mythic Raid" end
    key = key:gsub("|", " ")
    key = key:gsub("_", " ")
    key = key:gsub("(%l)(%u)", "%1 %2")
    key = key:gsub("(%u)(%u%l)", "%1 %2")
    if key:find("%u") and not key:find("%l") then key = key:lower() end
    key = key:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if key == "" then return "" end
    local label = key:gsub("^%l", string.upper)
    label = label:gsub(" To ", " to "):gsub(" Of ", " of "):gsub(" And ", " and "):gsub(" Or ", " or "):gsub(" In ", " in ")
    return label
end
A.HumanizeDisplayKey = A.HumanizeDisplayKey or HumanizeKeyLabel

local LOCALIZED_LABEL_CODES = {
    de = true,
    fr = true,
    es = true,
    pt = true,
    it = true,
    ru = true,
    ko = true,
    zh = true,
}

local LOCALIZED_LABEL_TOKENS = {
    gruppen = true,
    gesundheit = true,
    klassen = true,
    zauber = true,
    menue = true,
    ["men\195\188"] = true,
    zurueck = true,
    ["zur\195\188ck"] = true,
    weiter = true,
    abbrechen = true,
    anwenden = true,
    hilfe = true,
    groupe = true,
    cadre = true,
    cadres = true,
    sante = true,
    ["sant\195\169"] = true,
    ressources = true,
    indicateurs = true,
    annuler = true,
    appliquer = true,
    grupo = true,
    grupos = true,
    diseno = true,
    ["dise\195\177o"] = true,
    salud = true,
    recursos = true,
    indicadores = true,
    cancelar = true,
    aplicar = true,
    saude = true,
    ["sa\195\186de"] = true,
    feitico = true,
    ["feiti\195\167o"] = true,
    gruppo = true,
    salute = true,
    risorse = true,
    indicatori = true,
    annulla = true,
    applica = true,
}

local function LooksLocalizedAssistantLabel(label)
    label = tostring(label or "")
    if label == "" then return false end
    local normalized = label:lower()
    normalized = normalized:gsub("[%c%p]+", " ")
    normalized = normalized:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if normalized == "" then return false end

    local tokens = {}
    for token in normalized:gmatch("%S+") do
        tokens[#tokens + 1] = token
    end
    if #tokens > 1 and LOCALIZED_LABEL_CODES[tokens[1]] then return true end
    for i = 1, #tokens do
        if LOCALIZED_LABEL_TOKENS[tokens[i]] then return true end
    end
    return false
end

local PAGE_DISPLAY_LABELS = {
    home = "Dashboard",
    profiles = "Profiles",
    gameplay = "Gameplay",
    classpower = "Class Resources",
    modules = "Modules",
    search = "Search",

    opt_castbar = "Cast Bars",
    opt_bars = "Bars",
    opt_colors = "Colors",
    opt_fonts = "Fonts",
    opt_misc = "Miscellaneous",

    gf_layout = "Group Layout",
    gf_bars = "Group Dispel Overlay",
    gf_indicators = "Group Status & Indicators",
    gf_auras = "Group Auras",

    auras3 = "Auras",
    auras3_buffs = "Aura Buffs",
    auras3_debuffs = "Aura Debuffs",
    auras3_custom = "Custom Auras",
    auras3_filters = "Aura Filters",
    auras3_styling = "Aura Style",

    uf_player = "Player",
    uf_target = "Target",
    uf_focus = "Focus",
    uf_pet = "Pet",
    uf_boss = "Boss Frames",
    uf_targettarget = "Target of Target",
    uf_focustarget = "Focus Target",
}

function A.DisplayPageLabel(page, fallback)
    page = tostring(page or "")
    if page ~= "" and PAGE_DISPLAY_LABELS[page] then return PAGE_DISPLAY_LABELS[page] end
    return tostring(fallback or "MSUF page")
end

function A.IsKnownPageKey(page)
    page = tostring(page or "")
    return PAGE_DISPLAY_LABELS[page] ~= nil
end

function A.DisplayUnitLabel(unit)
    unit = tostring(unit or "")
    local labels = A.UnitLabels or UNIT_LABELS or {}
    local label = labels[unit]
    if label ~= nil and tostring(label) ~= "" then return tostring(label) end
    if unit == "targettarget" then return "Target of Target" end
    if unit == "focustarget" then return "Focus Target" end
    if unit == "mythicraid" then return "Mythic Raid" end
    return HumanizeKeyLabel(unit)
end

function A.DisplayGroupLabel(scope)
    scope = tostring(scope or "party")
    if scope == "gf_party" then scope = "party" end
    if scope == "gf_raid" then scope = "raid" end
    if scope == "gf_mythicraid" then scope = "mythicraid" end
    if scope == "mythicraid" then return "Mythic Raid" end
    if scope == "raid" then return "Raid" end
    if scope == "party" then return "Party" end
    return A.DisplayUnitLabel(scope)
end

function A.DisplayEnumLabel(label, value)
    if label ~= nil
        and tostring(label) ~= ""
        and tostring(label) ~= tostring(value or "")
        and not LooksLocalizedAssistantLabel(label)
    then
        return tostring(label)
    end
    local parser = A.Parser
    if parser and type(parser.ValueDisplay) == "function" then
        local display = parser.ValueDisplay({ type = "enum" }, value)
        if display ~= nil and tostring(display) ~= "" then return tostring(display) end
    end
    return HumanizeKeyLabel(value)
end

local function DisplayScopedKeyLabel(key)
    key = tostring(key or "")
    if key == "" then return "MSUF option" end
    local prefix, rest = key:match("^([^%.]+)%.(.+)$")
    if not prefix or prefix == "" or not rest or rest == "" then return HumanizeKeyLabel(key) end
    if prefix == "general" or prefix == "bars" or prefix == "gameplay" or prefix == "menu" then
        return HumanizeKeyLabel(rest)
    end
    if prefix == "barScope" or prefix == "fontScope" then
        local scope, attr = rest:match("^([^%.]+)%.(.+)$")
        if scope and attr then
            if scope == "shared" then return HumanizeKeyLabel(attr) end
            return A.DisplayGroupLabel(scope) .. " " .. HumanizeKeyLabel(attr)
        end
    end
    if prefix == "gf_party" or prefix == "gf_raid" or prefix == "gf_mythicraid" then
        return A.DisplayGroupLabel(prefix) .. " " .. HumanizeKeyLabel(rest)
    end
    return A.DisplayUnitLabel(prefix) .. " " .. HumanizeKeyLabel(rest)
end

function A.DisplaySettingLabel(setting)
    local label = setting and setting.label
    if label ~= nil
        and tostring(label) ~= ""
        and tostring(label) ~= tostring(setting and setting.key or "")
        and not LooksLocalizedAssistantLabel(label)
    then
        return tostring(label)
    end
    return DisplayScopedKeyLabel(setting and setting.key or label)
end

local SETTING_CONTROL_NOUNS = {
    boolean = "on/off option",
    enum = "choice control",
    number = "number control",
    color = "color control",
}

local function StringSettingControlNoun(setting)
    local presentation = tostring(setting and setting.presentationKind or ""):lower()
    if presentation ~= "" then return presentation end

    local mediaType = tostring(setting and setting.mediaType or ""):lower()
    local resolver = A.MediaResolver
    if mediaType == "" and resolver and type(resolver.MediaTypeForSetting) == "function" then
        local ok, resolved = pcall(resolver.MediaTypeForSetting, setting)
        if ok then mediaType = tostring(resolved or ""):lower() end
    end
    if mediaType:find("font", 1, true) then return "font choice" end
    if mediaType:find("border", 1, true) then return "border texture choice" end
    if mediaType:find("texture", 1, true) or mediaType:find("statusbar", 1, true) then return "texture choice" end

    local hint = table.concat({
        tostring(setting and setting.key or ""),
        tostring(setting and setting.label or ""),
        tostring(setting and setting.category or ""),
        tostring(setting and (setting.description or setting.summary) or ""),
    }, " "):lower()
    if hint:find("anchor frame", 1, true) or hint:find("frame name", 1, true) then return "frame name" end
    if hint:find("custom icon", 1, true) then return "custom icon" end
    if hint:find("texture", 1, true) then return "texture choice" end
    if hint:find("font", 1, true) and not hint:find("text", 1, true) then return "font choice" end
    if hint:find("style", 1, true) or hint:find("icon pack", 1, true)
        or hint:find("icon set", 1, true) or hint:find("preset", 1, true)
        or hint:find("media list", 1, true)
    then
        return "style choice"
    end
    return "text or named value"
end

-- Registry types stay machine-readable for parsing and validation. This helper
-- is the only presentation layer for those types, so conversational output
-- never asks a player to understand implementation words such as "enum" or
-- assumes that every string-backed option is a free-text box.
function A.DisplaySettingControl(settingOrType, form)
    local setting = type(settingOrType) == "table" and settingOrType or { type = settingOrType }
    local controlType = tostring(setting.type or "setting")
    local noun = SETTING_CONTROL_NOUNS[controlType]
        or (controlType == "string" and StringSettingControlNoun(setting))
        or "MSUF option"
    if form == "article" then
        local first = noun:sub(1, 1):lower()
        return (first:match("[aeiou]") and "an " or "a ") .. noun
    end
    return noun
end

function A.DisplaySettingValueLabel(setting, valueLabel, fallbackLabel)
    local label = A.DisplaySettingLabel(setting)
    if label == nil or tostring(label) == "" then label = fallbackLabel or "MSUF option" end
    local value = valueLabel
    if value == nil or tostring(value) == "" then value = "value" end
    return tostring(label) .. ": " .. tostring(value)
end

function A.DisplayActionLabel(action)
    local label = action and action.label
    if label ~= nil
        and tostring(label) ~= ""
        and tostring(label) ~= tostring(action and action.key or "")
        and not LooksLocalizedAssistantLabel(label)
    then
        return tostring(label)
    end
    local key = tostring(action and action.key or label or "")
    if key == "" then return "Assistant action" end
    return HumanizeKeyLabel(key)
end

local BuildDBHelpers = A.RegistryCoreBuilders and A.RegistryCoreBuilders.BuildDBHelpers
local DBHelpers = type(BuildDBHelpers) == "function" and BuildDBHelpers({
    M = M,
    MSUF = MSUF,
}) or nil
if type(DBHelpers) ~= "table" then return end
local EnsureDB = DBHelpers.EnsureDB
local UnitDB = DBHelpers.UnitDB
local GeneralDB = DBHelpers.GeneralDB
local BarsDB = DBHelpers.BarsDB
local GameplayDB = DBHelpers.GameplayDB
local GroupDB = DBHelpers.GroupDB
local ClampNumber = DBHelpers.ClampNumber
local CallGlobal = DBHelpers.CallGlobal

local BuildApplyHelpers = A.RegistryCoreBuilders and A.RegistryCoreBuilders.BuildApplyHelpers
local ApplyHelpers = type(BuildApplyHelpers) == "function" and BuildApplyHelpers({
    M = M,
    MSUF = MSUF,
    EnsureDB = EnsureDB,
    CallGlobal = CallGlobal,
}) or nil
if type(ApplyHelpers) ~= "table" then return end
local AuraModel = ApplyHelpers.AuraModel
local EnsureAuraFallbackDB = ApplyHelpers.EnsureAuraFallbackDB

local BuildUnitAuraHelpers = A.RegistryCoreBuilders and A.RegistryCoreBuilders.BuildUnitAuraHelpers
local UnitAuraHelpers = type(BuildUnitAuraHelpers) == "function" and BuildUnitAuraHelpers({
    AuraModel = AuraModel,
    EnsureAuraFallbackDB = EnsureAuraFallbackDB,
    AURA_UNIT_FLAGS = AURA_UNIT_FLAGS,
    AURA_LANE_FIELDS = AURA_LANE_FIELDS,
    ClampNumber = ClampNumber,
}) or nil
if type(UnitAuraHelpers) ~= "table" then return end

local BuildGroupAuraHelpers = A.RegistryCoreBuilders and A.RegistryCoreBuilders.BuildGroupAuraHelpers
local GroupAuraHelpers = type(BuildGroupAuraHelpers) == "function" and BuildGroupAuraHelpers({
    GroupDB = GroupDB,
    ClampNumber = ClampNumber,
}) or nil
if type(GroupAuraHelpers) ~= "table" then return end

local function UnitDefaultPower(unit)
    return not (unit == "pet" or unit == "targettarget" or unit == "focustarget")
end

local InstallRegistryCoreContext = A.RegistryCoreBuilders and A.RegistryCoreBuilders.InstallRegistryCoreContext
if type(InstallRegistryCoreContext) ~= "function" then return end
if not InstallRegistryCoreContext({
    M = M,
    A = A,
    Registry = Registry,
    CoreData = CoreData,
    DBHelpers = DBHelpers,
    ApplyHelpers = ApplyHelpers,
    UnitAuraHelpers = UnitAuraHelpers,
    GroupAuraHelpers = GroupAuraHelpers,
    UnitDefaultPower = UnitDefaultPower,
}) then return end
