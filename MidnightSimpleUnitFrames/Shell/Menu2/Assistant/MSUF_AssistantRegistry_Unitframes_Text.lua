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

function A.UnitframesRegistry.RegisterTextSettings(ctx, unit)
    if type(ctx) ~= "table" or type(unit) ~= "string" then return end

    local MakeAliases = ctx.MakeAliases
    local RegisterUnitBooleanSetting = ctx.RegisterUnitBooleanSetting
    local RegisterUnitEnum = ctx.RegisterUnitEnum
    local RegisterUnitTextNumber = ctx.RegisterUnitTextNumber
    local TextValue = ctx.TextValue

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

    RegisterUnitEnum(unit, "nameTextAnchor", "nameTextAnchor", "Name Text Anchor", "LEFT", TEXT_ANCHOR_VALUES, MakeAliases(unit, "name anchor", "name text anchor"), {
        category = "Text",
        text = true,
        valueAliases = { left = "LEFT", center = "CENTER", middle = "CENTER", right = "RIGHT" },
        get = function(unitKey) return TextValue(unitKey, "nameTextAnchor", "LEFT") end,
    })
    RegisterUnitTextNumber(unit, "nameOffsetX", "nameOffsetX", "Name X Offset", 4,
        MakeAliases(unit, "name x", "name x offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "nameOffsetY", "nameOffsetY", "Name Y Offset", -4,
        MakeAliases(unit, "name y", "name y offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "nameFontSize", "nameFontSize", "Name Font Size", 14,
        MakeAliases(unit, "name size", "name font size"), { min = 6, max = 48, fonts = true, generalKey = "nameFontSize" })

    RegisterUnitEnum(unit, "hpTextLeft", "textLeft", "HP Left Slot", "NONE", HP_MODE_VALUES,
        MakeAliases(unit, "hp left slot", "health left slot", "left hp text"),
        {
            category = "Text",
            text = true,
            valueAliases = HP_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "textLeft", TextValue(unitKey, "hpTextMode", "NONE")) end,
        })
    RegisterUnitEnum(unit, "hpTextCenter", "textCenter", "HP Center Slot", "NONE", HP_MODE_VALUES,
        MakeAliases(unit, "hp center slot", "health center slot", "center hp text"),
        {
            category = "Text",
            text = true,
            valueAliases = HP_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "textCenter", TextValue(unitKey, "hpTextMode", "NONE")) end,
        })
    RegisterUnitEnum(unit, "hpTextRight", "textRight", "HP Right Slot", "CURPERCENT", HP_MODE_VALUES,
        MakeAliases(unit, "hp right slot", "health right slot", "right hp text"),
        {
            category = "Text",
            text = true,
            valueAliases = HP_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "textRight", TextValue(unitKey, "hpTextMode", "CURPERCENT")) end,
        })
    RegisterUnitEnum(unit, "hpTextSeparator", "hpTextSeparator", "HP Text Delimiter", "", SEPARATOR_VALUES,
        MakeAliases(unit, "hp text delimiter", "hp text separator", "health text delimiter"),
        { category = "Text", text = true, valueAliases = SEPARATOR_ALIASES, get = function(unitKey) return TextValue(unitKey, "hpTextSeparator", "") end })
    RegisterUnitBooleanSetting(unit, "hpTextReverse", "hpTextReverse", "Reverse HP Text Order", false,
        MakeAliases(unit, "reverse hp text", "hp text reverse order"), { category = "Text", text = true })
    RegisterUnitTextNumber(unit, "hpOffsetX", "hpOffsetX", "HP Text X Offset", -4,
        MakeAliases(unit, "hp text x", "health text x offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "hpOffsetY", "hpOffsetY", "HP Text Y Offset", -4,
        MakeAliases(unit, "hp text y", "health text y offset"), { min = -300, max = 300 })
    RegisterUnitTextNumber(unit, "hpFontSize", "hpFontSize", "HP Font Size", 14,
        MakeAliases(unit, "hp text size", "hp font size", "health text size"), { min = 6, max = 48, fonts = true, generalKey = "hpFontSize" })

    RegisterUnitEnum(unit, "powerTextLeft", "powerTextLeft", "Power Left Slot", "NONE", POWER_MODE_VALUES,
        MakeAliases(unit, "power left slot", "mana left slot", "left power text"),
        {
            category = "Text",
            text = true,
            valueAliases = POWER_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "powerTextLeft", TextValue(unitKey, "powerTextMode", "NONE")) end,
        })
    RegisterUnitEnum(unit, "powerTextCenter", "powerTextCenter", "Power Center Slot", "NONE", POWER_MODE_VALUES,
        MakeAliases(unit, "power center slot", "mana center slot", "center power text"),
        {
            category = "Text",
            text = true,
            valueAliases = POWER_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "powerTextCenter", TextValue(unitKey, "powerTextMode", "NONE")) end,
        })
    RegisterUnitEnum(unit, "powerTextRight", "powerTextRight", "Power Right Slot", "CURPERCENT", POWER_MODE_VALUES,
        MakeAliases(unit, "power right slot", "mana right slot", "right power text"),
        {
            category = "Text",
            text = true,
            valueAliases = POWER_MODE_ALIASES,
            get = function(unitKey) return TextValue(unitKey, "powerTextRight", TextValue(unitKey, "powerTextMode", "CURPERCENT")) end,
        })
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
    RegisterUnitTextNumber(unit, "powerFontSize", "powerFontSize", "Power Font Size", 14,
        MakeAliases(unit, "power text size", "power font size", "mana text size"), { min = 6, max = 48, fonts = true, generalKey = "powerFontSize" })

    local hpSlots = {
        { suffix = "Left", label = "HP Left Slot", keyPrefix = "hpTextLeft", alias = "hp left slot" },
        { suffix = "Center", label = "HP Center Slot", keyPrefix = "hpTextCenter", alias = "hp center slot" },
        { suffix = "Right", label = "HP Right Slot", keyPrefix = "hpTextRight", alias = "hp right slot" },
    }
    for s = 1, #hpSlots do
        local slot = hpSlots[s]
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetX", slot.keyPrefix .. "OffsetX", slot.label .. " X Offset", 0,
            MakeAliases(unit, slot.alias .. " x", slot.alias .. " x offset"), { min = -300, max = 300 })
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetY", slot.keyPrefix .. "OffsetY", slot.label .. " Y Offset", 0,
            MakeAliases(unit, slot.alias .. " y", slot.alias .. " y offset"), { min = -300, max = 300 })
    end
    local powerSlots = {
        { label = "Power Left Slot", keyPrefix = "powerTextLeft", alias = "power left slot" },
        { label = "Power Center Slot", keyPrefix = "powerTextCenter", alias = "power center slot" },
        { label = "Power Right Slot", keyPrefix = "powerTextRight", alias = "power right slot" },
    }
    for s = 1, #powerSlots do
        local slot = powerSlots[s]
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetX", slot.keyPrefix .. "OffsetX", slot.label .. " X Offset", 0,
            MakeAliases(unit, slot.alias .. " x", slot.alias .. " x offset"), { min = -300, max = 300 })
        RegisterUnitTextNumber(unit, slot.keyPrefix .. "OffsetY", slot.keyPrefix .. "OffsetY", slot.label .. " Y Offset", 0,
            MakeAliases(unit, slot.alias .. " y", slot.alias .. " y offset"), { min = -300, max = 300 })
    end

    RegisterUnitTextNumber(unit, "nameTextLayer", "nameTextLayer", "Name Text Layer", 5,
        MakeAliases(unit, "name text layer", "name layer"), { min = 0, max = 30, fonts = true })
    RegisterUnitTextNumber(unit, "hpTextLayer", "hpTextLayer", "HP Text Layer", 5,
        MakeAliases(unit, "hp text layer", "health text layer"), { min = 0, max = 30, fonts = true })
    RegisterUnitTextNumber(unit, "powerTextLayer", "powerTextLayer", "Power Text Layer", 2,
        MakeAliases(unit, "power text layer", "mana text layer"), { min = 0, max = 30, fonts = true })
end
