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
    if label ~= nil and tostring(label) ~= "" and tostring(label) ~= tostring(value or "") then return tostring(label) end
    local parser = A.Parser
    if parser and type(parser.ValueDisplay) == "function" then
        local ok, display = pcall(parser.ValueDisplay, { type = "enum" }, value)
        if ok and display ~= nil and tostring(display) ~= "" then return tostring(display) end
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
    if label ~= nil and tostring(label) ~= "" and tostring(label) ~= tostring(setting and setting.key or "") then return tostring(label) end
    return DisplayScopedKeyLabel(setting and setting.key or label)
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
    if label ~= nil and tostring(label) ~= "" and tostring(label) ~= tostring(action and action.key or "") then return tostring(label) end
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
