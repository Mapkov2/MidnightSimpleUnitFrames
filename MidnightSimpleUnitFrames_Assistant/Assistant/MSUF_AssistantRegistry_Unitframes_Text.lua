-- Assistant UnitFrame text registry.
-- Keeps per-unit name, health, and power text metadata outside the main
-- UnitFrame registry loop while preserving the same cold registration behavior.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

local function AppendAliases(aliases, ...)
    if type(aliases) ~= "table" then return aliases end
    for i = 1, select("#", ...) do
        local alias = select(i, ...)
        if type(alias) == "string" and alias ~= "" then
            aliases[#aliases + 1] = alias
        end
    end
    return aliases
end

local function CanonicalUnitNameAnchor(value)
    value = tostring(value or "TOPLEFT"):upper()
    if value == "LEFT" then return "TOPLEFT" end
    if value == "CENTER" then return "TOP" end
    if value == "RIGHT" then return "TOPRIGHT" end
    return value
end

function A.UnitframesRegistry.RegisterTextSettings(ctx, unit)
    if type(ctx) ~= "table" or type(unit) ~= "string" then return end

    local MakeAliases = ctx.MakeAliases
    local RegisterUnitBooleanSetting = ctx.RegisterUnitBooleanSetting
    local RegisterUnitEnum = ctx.RegisterUnitEnum
    local RegisterUnitTextNumber = ctx.RegisterUnitTextNumber
    local TextValue = ctx.TextValue
    local UnitDB = ctx.UnitDB
    local GeneralDB = ctx.GeneralDB

    if type(MakeAliases) ~= "function" or type(RegisterUnitBooleanSetting) ~= "function" then return end
    if type(RegisterUnitEnum) ~= "function" or type(RegisterUnitTextNumber) ~= "function" then return end
    if type(TextValue) ~= "function" then return end

    local TEXT_ANCHOR_VALUES = ctx.TEXT_ANCHOR_VALUES or {}
    local HP_MODE_VALUES = ctx.HP_MODE_VALUES or {}
    local HP_MODE_ALIASES = ctx.HP_MODE_ALIASES
    local POWER_MODE_VALUES = ctx.POWER_MODE_VALUES or {}
    local POWER_MODE_ALIASES = ctx.POWER_MODE_ALIASES
    local SEPARATOR_VALUES = ctx.SEPARATOR_VALUES or {}
    local SEPARATOR_ALIASES = ctx.SEPARATOR_ALIASES

    RegisterUnitEnum(unit, "nameTextAnchor", "nameTextAnchor", "Name Text Anchor", "TOPLEFT", TEXT_ANCHOR_VALUES, MakeAliases(unit, "name anchor", "name text anchor"), {
        category = "Text",
        text = true,
        valueLabels = {
            TOPLEFT = "Top Left", TOP = "Top Center", TOPRIGHT = "Top Right",
            FRAMELEFT = "Left", FRAMECENTER = "Center", FRAMERIGHT = "Right",
        },
        valueAliases = {
            ["top left"] = "TOPLEFT", ["upper left"] = "TOPLEFT",
            top = "TOP", ["top center"] = "TOP", ["upper center"] = "TOP",
            ["top right"] = "TOPRIGHT", ["upper right"] = "TOPRIGHT",
            left = "FRAMELEFT",
            center = "FRAMECENTER", centre = "FRAMECENTER", middle = "FRAMECENTER",
            right = "FRAMERIGHT",
        },
        get = function(unitKey) return CanonicalUnitNameAnchor(TextValue(unitKey, "nameTextAnchor", "TOPLEFT")) end,
    })
    RegisterUnitTextNumber(unit, "nameOffsetX", "nameOffsetX", "Name X Offset", 4,
        MakeAliases(unit, "name x", "name x offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "nameOffsetY", "nameOffsetY", "Name Y Offset", -4,
        MakeAliases(unit, "name y", "name y offset"), { min = -300, max = 300 })
    local nameFontAliases = MakeAliases(unit, "name size", "name font size")
    AppendAliases(nameFontAliases, "unit name text size", "unit frame name text size", "unit name font size")
    RegisterUnitTextNumber(unit, "nameFontSize", "nameFontSize", "Name Font Size", 14,
        nameFontAliases, { min = 6, max = 48, fonts = true, generalKey = "nameFontSize" })

    local hpLeftAliases = MakeAliases(unit, "hp left slot", "health left slot", "left hp text")
    AppendAliases(hpLeftAliases, "unit text slot", "unit text left slot", "unit hp left slot", "unit health left slot", "unit health text left slot")
    RegisterUnitEnum(unit, "hpTextLeft", "textLeft", "HP Left Slot", "NONE", HP_MODE_VALUES,
        hpLeftAliases,
        {
            category = "Text",
            text = true,
            valueAliases = HP_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "textLeft", TextValue(unitKey, "hpTextMode", "NONE")) end,
        })
    -- Players say where they want the text, not which "slot" it is:
    -- "put the health number in the middle" names this control.
    local hpCenterAliases = MakeAliases(unit, "hp center slot", "health center slot", "center hp text",
        "health text in the middle", "health number in the middle", "hp in the middle",
        "health in the middle", "health text in the center", "health number in the center",
        "hp in the center", "health in the center", "middle health text", "middle hp text",
        "lebenspunkte in der mitte", "hp in der mitte", "leben in der mitte")
    AppendAliases(hpCenterAliases, "unit text slot", "unit text center slot", "unit text middle slot", "unit hp center slot", "unit health center slot", "unit health text center slot")
    -- The same phrases unscoped, so a request that names no frame still finds
    -- this control on every unit and can be answered with "which frame?"
    -- instead of a generic examples list.
    AppendAliases(hpCenterAliases,
        "health text in the middle", "health number in the middle", "hp in the middle",
        "health in the middle", "health number in the center", "health text in the center",
        "lebenspunkte in der mitte", "hp in der mitte")
    RegisterUnitEnum(unit, "hpTextCenter", "textCenter", "HP Center Slot", "NONE", HP_MODE_VALUES,
        hpCenterAliases,
        {
            category = "Text",
            text = true,
            valueAliases = HP_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "textCenter", TextValue(unitKey, "hpTextMode", "NONE")) end,
        })
    local hpRightAliases = MakeAliases(unit, "hp right slot", "health right slot", "right hp text")
    AppendAliases(hpRightAliases, "unit text slot", "unit text right slot", "unit hp right slot", "unit health right slot", "unit health text right slot")
    RegisterUnitEnum(unit, "hpTextRight", "textRight", "HP Right Slot", "CURPERCENT", HP_MODE_VALUES,
        hpRightAliases,
        {
            category = "Text",
            text = true,
            valueAliases = HP_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "textRight", TextValue(unitKey, "hpTextMode", "CURPERCENT")) end,
        })
    local function PercentSignVisible(unitKey, dbKey)
        local conf = type(UnitDB) == "function" and UnitDB(unitKey) or nil
        local value = type(conf) == "table" and conf[dbKey] or nil
        if value ~= nil then return value ~= true end
        local g = type(GeneralDB) == "function" and GeneralDB() or nil
        return not (type(g) == "table" and g.hidePercentSymbol == true)
    end
    local function SetPercentSignVisible(unitKey, dbKey, visible)
        local conf = type(UnitDB) == "function" and UnitDB(unitKey) or nil
        if type(conf) == "table" then
            conf[dbKey] = not (visible and true or false)
        end
    end
    local function RegisterHidePercent(attr, dbKey, label, ...)
        local aliases = MakeAliases(unit, ...)
        AppendAliases(aliases, "hide percent sign", "hide percent symbol", "hide % sign", "hide percentage sign")
        RegisterUnitBooleanSetting(unit, attr, dbKey, label, false, aliases, { category = "Text", text = true, matchLabel = false })
    end
    local function RegisterPercentSign(attr, dbKey, label, ...)
        local aliases = MakeAliases(unit, ...)
        AppendAliases(aliases, "percent sign", "percent symbol", "% sign", "percentage sign")
        RegisterUnitBooleanSetting(unit, attr, dbKey, label, true, aliases, {
            category = "Text",
            text = true,
            keySuffix = attr,
            get = function(unitKey) return PercentSignVisible(unitKey, dbKey) end,
            set = function(unitKey, value) SetPercentSignVisible(unitKey, dbKey, value) end,
        })
    end
    RegisterHidePercent("hpTextLeftHidePercentSymbol", "hpTextLeftHidePercentSymbol", "HP Left Hide % Sign", "hp left hide percent sign", "left hp hide percent sign", "health left hide percent sign", "left health hide percent sign", "hide hp left percent sign", "hide health left percent sign", "hide left hp percent sign")
    RegisterPercentSign("hpTextLeftPercentSymbol", "hpTextLeftHidePercentSymbol", "HP Left % Sign", "hp left percent sign", "health left percent sign", "left hp percent sign", "hp left % sign", "left hp % sign")
    RegisterHidePercent("hpTextCenterHidePercentSymbol", "hpTextCenterHidePercentSymbol", "HP Center Hide % Sign", "hp center hide percent sign", "center hp hide percent sign", "hp middle hide percent sign", "health center hide percent sign", "center health hide percent sign", "hide hp center percent sign", "hide health center percent sign", "hide center hp percent sign", "hide hp middle percent sign")
    RegisterPercentSign("hpTextCenterPercentSymbol", "hpTextCenterHidePercentSymbol", "HP Center % Sign", "hp center percent sign", "health center percent sign", "center hp percent sign", "hp middle percent sign", "middle hp percent sign", "hp center % sign")
    RegisterHidePercent("hpTextRightHidePercentSymbol", "hpTextRightHidePercentSymbol", "HP Right Hide % Sign", "hp right hide percent sign", "right hp hide percent sign", "health right hide percent sign", "right health hide percent sign", "hide hp right percent sign", "hide health right percent sign", "hide right hp percent sign")
    RegisterPercentSign("hpTextRightPercentSymbol", "hpTextRightHidePercentSymbol", "HP Right % Sign", "hp right percent sign", "health right percent sign", "right hp percent sign", "hp right % sign", "right hp % sign")
    RegisterUnitEnum(unit, "hpTextSeparator", "hpTextSeparator", "HP Text Delimiter", "", SEPARATOR_VALUES,
        MakeAliases(unit, "hp text delimiter", "hp text separator", "health text delimiter"),
        { category = "Text", text = true, valueAliases = SEPARATOR_ALIASES, get = function(unitKey) return TextValue(unitKey, "hpTextSeparator", "") end })
    RegisterUnitBooleanSetting(unit, "hpTextReverse", "hpTextReverse", "Reverse HP Text Order", false,
        MakeAliases(unit, "reverse hp text", "hp text reverse order"), { category = "Text", text = true })
    RegisterUnitBooleanSetting(unit, "healthTextDecimals", "healthTextDecimals", "Health Text Decimals", false,
        MakeAliases(unit, "health text decimals", "hp text decimals", "decimal percent"), { category = "Text", text = true })
    local hpAbbreviationAliases = MakeAliases(unit,
        "abbreviate hp values", "abbreviate health values", "shorten hp values",
        "short hp numbers", "abbreviated hp numbers", "hp value abbreviation")
    AppendAliases(hpAbbreviationAliases,
        "abbreviate unit hp values", "abbreviate unit health values", "unit hp value abbreviation")
    RegisterUnitBooleanSetting(unit, "hpFullValueShort", "hpFullValueShort", "Abbreviate HP Values", true,
        hpAbbreviationAliases, {
            category = "Text",
            text = true,
            reason = "MSUF2_HP_FULL_VALUE_SHORT",
            get = function(unitKey)
                local conf = type(UnitDB) == "function" and UnitDB(unitKey) or nil
                if type(conf) == "table" and conf.hpFullValueShort ~= nil then
                    return conf.hpFullValueShort == true
                end
                local general = type(GeneralDB) == "function" and GeneralDB() or nil
                return type(general) ~= "table" or general.useShortNumbers ~= false
            end,
            set = function(unitKey, value)
                local conf = type(UnitDB) == "function" and UnitDB(unitKey) or nil
                if type(conf) ~= "table" then return end
                conf.hpFullValueShort = value and true or false
                -- Match the native text setter: an explicit per-unit choice
                -- replaces the legacy combined HP/power text override.
                conf.hpPowerTextOverride = nil
            end,
            description = "Abbreviates numeric HP values with K/M. None and Percent-only HP slots are unaffected.",
        })
    RegisterUnitTextNumber(unit, "hpOffsetX", "hpOffsetX", "HP Text X Offset", -4,
        MakeAliases(unit, "hp text x", "health text x offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "hpOffsetY", "hpOffsetY", "HP Text Y Offset", -4,
        MakeAliases(unit, "hp text y", "health text y offset"), { min = -300, max = 300 })
    local hpFontAliases = MakeAliases(unit, "hp text size", "hp font size", "health text size")
    AppendAliases(hpFontAliases, "unit text size", "unit frame text size", "unit hp text size", "unit health text size", "unit health font size")
    RegisterUnitTextNumber(unit, "hpFontSize", "hpFontSize", "HP Font Size", 14,
        hpFontAliases, { min = 6, max = 48, fonts = true, generalKey = "hpFontSize" })

    local powerLeftAliases = MakeAliases(unit, "power left slot", "mana left slot", "left power text")
    AppendAliases(powerLeftAliases, "unit text slot", "unit text left slot", "unit power left slot", "unit mana left slot", "unit power text left slot")
    RegisterUnitEnum(unit, "powerTextLeft", "powerTextLeft", "Power Left Slot", "NONE", POWER_MODE_VALUES,
        powerLeftAliases,
        {
            category = "Text",
            text = true,
            valueAliases = POWER_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "powerTextLeft", TextValue(unitKey, "powerTextMode", "NONE")) end,
        })
    local powerCenterAliases = MakeAliases(unit, "power center slot", "mana center slot", "center power text")
    AppendAliases(powerCenterAliases, "unit text slot", "unit text center slot", "unit text middle slot", "unit power center slot", "unit mana center slot", "unit power text center slot")
    RegisterUnitEnum(unit, "powerTextCenter", "powerTextCenter", "Power Center Slot", "NONE", POWER_MODE_VALUES,
        powerCenterAliases,
        {
            category = "Text",
            text = true,
            valueAliases = POWER_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "powerTextCenter", TextValue(unitKey, "powerTextMode", "NONE")) end,
        })
    local powerRightAliases = MakeAliases(unit, "power right slot", "mana right slot", "right power text")
    AppendAliases(powerRightAliases, "unit text slot", "unit text right slot", "unit power right slot", "unit mana right slot", "unit power text right slot")
    RegisterUnitEnum(unit, "powerTextRight", "powerTextRight", "Power Right Slot", "CURPERCENT", POWER_MODE_VALUES,
        powerRightAliases,
        {
            category = "Text",
            text = true,
            valueAliases = POWER_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "powerTextRight", TextValue(unitKey, "powerTextMode", "CURPERCENT")) end,
        })
    RegisterHidePercent("powerTextLeftHidePercentSymbol", "powerTextLeftHidePercentSymbol", "Power Left Hide % Sign", "power left hide percent sign", "left power hide percent sign", "mana left hide percent sign", "left mana hide percent sign", "hide power left percent sign", "hide mana left percent sign", "hide left power percent sign")
    RegisterPercentSign("powerTextLeftPercentSymbol", "powerTextLeftHidePercentSymbol", "Power Left % Sign", "power left percent sign", "mana left percent sign", "left power percent sign", "power left % sign", "left power % sign")
    RegisterHidePercent("powerTextCenterHidePercentSymbol", "powerTextCenterHidePercentSymbol", "Power Center Hide % Sign", "power center hide percent sign", "center power hide percent sign", "power middle hide percent sign", "mana center hide percent sign", "center mana hide percent sign", "hide power center percent sign", "hide mana center percent sign", "hide center power percent sign", "hide power middle percent sign")
    RegisterPercentSign("powerTextCenterPercentSymbol", "powerTextCenterHidePercentSymbol", "Power Center % Sign", "power center percent sign", "mana center percent sign", "center power percent sign", "power middle percent sign", "middle power percent sign", "power center % sign")
    RegisterHidePercent("powerTextRightHidePercentSymbol", "powerTextRightHidePercentSymbol", "Power Right Hide % Sign", "power right hide percent sign", "right power hide percent sign", "mana right hide percent sign", "right mana hide percent sign", "hide power right percent sign", "hide mana right percent sign", "hide right power percent sign")
    RegisterPercentSign("powerTextRightPercentSymbol", "powerTextRightHidePercentSymbol", "Power Right % Sign", "power right percent sign", "mana right percent sign", "right power percent sign", "power right % sign", "right power % sign")
    RegisterUnitEnum(unit, "powerTextSeparator", "powerTextSeparator", "Power Text Delimiter", "", SEPARATOR_VALUES,
        MakeAliases(unit, "power text delimiter", "power text separator", "mana text delimiter"),
        {
            category = "Text",
            text = true,
            valueAliases = SEPARATOR_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "powerTextSeparator", TextValue(unitKey, "hpTextSeparator", "")) end,
        })
    RegisterUnitTextNumber(unit, "powerOffsetX", "powerOffsetX", "Power Text X Offset", -4,
        MakeAliases(unit, "power text x", "mana text x offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "powerOffsetY", "powerOffsetY", "Power Text Y Offset", 4,
        MakeAliases(unit, "power text y", "mana text y offset"), { min = -300, max = 300 })
    local powerFontAliases = MakeAliases(unit, "power text size", "power font size", "mana text size")
    AppendAliases(powerFontAliases, "unit text size", "unit frame text size", "unit power text size", "unit mana text size", "unit power font size")
    RegisterUnitTextNumber(unit, "powerFontSize", "powerFontSize", "Power Font Size", 14,
        powerFontAliases, { min = 6, max = 48, fonts = true, generalKey = "powerFontSize" })

    local hpSlots = {
        { suffix = "Left", label = "HP Left Slot", keyPrefix = "hpTextLeft", alias = "hp left slot" },
        { suffix = "Center", label = "HP Center Slot", keyPrefix = "hpTextCenter", alias = "hp center slot" },
        { suffix = "Right", label = "HP Right Slot", keyPrefix = "hpTextRight", alias = "hp right slot" },
    }
    for s = 1, #hpSlots do
        local slot = hpSlots[s]
        local slotLower = tostring(slot.suffix or ""):lower()
        if slotLower == "center" then slotLower = "center" end
        local slotXAliases = MakeAliases(unit, slot.alias .. " x", slot.alias .. " x offset")
        AppendAliases(slotXAliases,
            "unit text slot x", "unit text slot x offset",
            "unit text " .. slotLower .. " slot x", "unit text " .. slotLower .. " slot x offset",
            "unit hp " .. slotLower .. " slot x", "unit hp " .. slotLower .. " slot x offset",
            "unit health " .. slotLower .. " slot x", "unit health " .. slotLower .. " slot x offset"
        )
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetX", slot.keyPrefix .. "OffsetX", slot.label .. " X Offset", 0,
            slotXAliases, { min = -300, max = 300 })
        local slotYAliases = MakeAliases(unit, slot.alias .. " y", slot.alias .. " y offset")
        AppendAliases(slotYAliases,
            "unit text slot y", "unit text slot y offset",
            "unit text " .. slotLower .. " slot y", "unit text " .. slotLower .. " slot y offset",
            "unit hp " .. slotLower .. " slot y", "unit hp " .. slotLower .. " slot y offset",
            "unit health " .. slotLower .. " slot y", "unit health " .. slotLower .. " slot y offset"
        )
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetY", slot.keyPrefix .. "OffsetY", slot.label .. " Y Offset", 0,
            slotYAliases, { min = -300, max = 300 })
    end
    local powerSlots = {
        { label = "Power Left Slot", keyPrefix = "powerTextLeft", alias = "power left slot" },
        { label = "Power Center Slot", keyPrefix = "powerTextCenter", alias = "power center slot" },
        { label = "Power Right Slot", keyPrefix = "powerTextRight", alias = "power right slot" },
    }
    for s = 1, #powerSlots do
        local slot = powerSlots[s]
        local slotLower = tostring(slot.label or ""):match("Power%s+(%S+)%s+Slot")
        slotLower = tostring(slotLower or ""):lower()
        local slotXAliases = MakeAliases(unit, slot.alias .. " x", slot.alias .. " x offset")
        AppendAliases(slotXAliases,
            "unit text slot x", "unit text slot x offset",
            "unit text " .. slotLower .. " slot x", "unit text " .. slotLower .. " slot x offset",
            "unit power " .. slotLower .. " slot x", "unit power " .. slotLower .. " slot x offset",
            "unit mana " .. slotLower .. " slot x", "unit mana " .. slotLower .. " slot x offset"
        )
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetX", slot.keyPrefix .. "OffsetX", slot.label .. " X Offset", 0,
            slotXAliases, { min = -300, max = 300 })
        local slotYAliases = MakeAliases(unit, slot.alias .. " y", slot.alias .. " y offset")
        AppendAliases(slotYAliases,
            "unit text slot y", "unit text slot y offset",
            "unit text " .. slotLower .. " slot y", "unit text " .. slotLower .. " slot y offset",
            "unit power " .. slotLower .. " slot y", "unit power " .. slotLower .. " slot y offset",
            "unit mana " .. slotLower .. " slot y", "unit mana " .. slotLower .. " slot y offset"
        )
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetY", slot.keyPrefix .. "OffsetY", slot.label .. " Y Offset", 0,
            slotYAliases, { min = -300, max = 300 })
    end

    RegisterUnitTextNumber(unit, "nameTextLayer", "nameTextLayer", "Name Text Layer", 5,
        MakeAliases(unit, "name text layer", "name layer"), { min = 0, max = 30, fonts = true })
    RegisterUnitTextNumber(unit, "hpTextLayer", "hpTextLayer", "HP Text Layer", 5,
        MakeAliases(unit, "hp text layer", "health text layer"), { min = 0, max = 30, fonts = true })
    RegisterUnitTextNumber(unit, "powerTextLayer", "powerTextLayer", "Power Text Layer", 2,
        MakeAliases(unit, "power text layer", "mana text layer"), { min = 0, max = 30, fonts = true })
end
